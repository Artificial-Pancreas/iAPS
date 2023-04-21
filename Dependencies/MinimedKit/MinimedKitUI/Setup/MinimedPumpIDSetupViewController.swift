//
//  MinimedPumpIDSetupViewController.swift
//  Loop
//
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//

import UIKit
import LoopKit
import LoopKitUI
import MinimedKit
import RileyLinkKit


class MinimedPumpIDSetupViewController: SetupTableViewController {

    var rileyLinkPumpManager: RileyLinkPumpManager!

    private enum RegionCode: String {
        case northAmerica = "NA"
        case canada = "CA/CM"
        case worldWide = "WW"

        var region: PumpRegion {
            switch self {
            case .northAmerica:
                return .northAmerica
            case .canada:
                return .canada
            case .worldWide:
                return .worldWide
            }
        }
    }

    private var pumpRegionCode: RegionCode? {
        didSet {
            regionAndColorPickerCell.regionLabel.text = pumpRegionCode?.region.description
            regionAndColorPickerCell.regionLabel.textColor = nil

            updateStateForSettings()
        }
    }

    private var pumpColor: PumpColor? {
        didSet {
            regionAndColorPickerCell.pumpImageView.image = .pumpImage(in: pumpColor, isLargerModel: true, isSmallImage: true)

            updateStateForSettings()
        }
    }

    private var pumpID: String? {
        get {
            return pumpIDTextField.text
        }
        set {
            pumpIDTextField.text = newValue
        }
    }

    private var pumpOps: PumpOps?

    private var pumpState: PumpState?
    
    private var pumpFirmwareVersion: String?

    var maxBasalRateUnitsPerHour: Double!

    var maxBolusUnits: Double!

    var basalSchedule: BasalRateSchedule!

    private var isSentrySetUpNeeded: Bool = false

    var pumpManagerState: MinimedPumpManagerState? {
        get {
            guard
                let navVC = navigationController as? MinimedPumpManagerSetupViewController,
                let insulinType = navVC.insulinType,
                let pumpColor = pumpColor,
                let pumpID = pumpID,
                let pumpModel = pumpState?.pumpModel,
                let pumpRegion = pumpRegionCode?.region,
                let timeZone = pumpState?.timeZone,
                let pumpFirmwareVersion = pumpFirmwareVersion
            else {
                return nil
            }
            
            return MinimedPumpManagerState(
                isOnboarded: false,
                useMySentry: pumpState?.useMySentry ?? true,
                pumpColor: pumpColor,
                pumpID: pumpID,
                pumpModel: pumpModel,
                pumpFirmwareVersion: pumpFirmwareVersion,
                pumpRegion: pumpRegion,
                rileyLinkConnectionState: rileyLinkPumpManager.rileyLinkConnectionManagerState,
                timeZone: timeZone,
                suspendState: .resumed(Date()),
                insulinType: insulinType,
                lastTuned: pumpState?.lastTuned,
                lastValidFrequency: pumpState?.lastValidFrequency,
                basalSchedule: BasalSchedule(repeatingScheduleValues: basalSchedule.items)
            )
        }
    }

    var pumpManager: MinimedPumpManager? {
        guard let pumpManagerState = pumpManagerState else {
            return nil
        }

        return MinimedPumpManager(
            state: pumpManagerState,
            rileyLinkDeviceProvider: rileyLinkPumpManager.rileyLinkDeviceProvider)
    }

    // MARK: -

    @IBOutlet weak var pumpIDTextField: UITextField!
    
    @IBOutlet fileprivate weak var regionAndColorPickerCell: RegionAndColorPickerTableViewCell!

    @IBOutlet weak var activityIndicator: SetupIndicatorView!

    @IBOutlet weak var loadingLabel: UILabel!

    override func viewDidLoad() {
        super.viewDidLoad()

        regionAndColorPickerCell.pickerView.delegate = self
        regionAndColorPickerCell.pickerView.dataSource = self

        continueState = .inputSettings

        NotificationCenter.default.addObserver(self, selector: #selector(keyboardDidHide), name: UIResponder.keyboardDidHideNotification, object: nil)
    }

    override func setEditing(_ editing: Bool, animated: Bool) {
        super.setEditing(editing, animated: animated)
    }

    // MARK: - UITableViewDelegate

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard continueState != .reading else {
            return
        }

        if let cell = tableView.cellForRow(at: indexPath) as? RegionAndColorPickerTableViewCell {
            cell.becomeFirstResponder()

            // Apply initial values to match the picker
            if pumpRegionCode == nil {
                pumpRegionCode = MinimedPumpIDSetupViewController.regionRows[0]
            }
            if pumpColor == nil {
                pumpColor = MinimedPumpIDSetupViewController.colorRows[0]
            }
        }

        tableView.deselectRow(at: indexPath, animated: true)
    }

    // MARK: - Navigation

    private enum State {
        case loadingView
        case inputSettings
        case readyToRead
        case reading
        case completed
    }

    private var continueState: State = .loadingView {
        didSet {
            switch continueState {
            case .loadingView:
                updateStateForSettings()
            case .inputSettings:
                pumpIDTextField.isEnabled = true
                activityIndicator.state = .hidden
                footerView.primaryButton.isEnabled = false
                footerView.primaryButton.setConnectTitle()
                lastError = nil
            case .readyToRead:
                pumpIDTextField.isEnabled = true
                activityIndicator.state = .hidden
                footerView.primaryButton.isEnabled = true
                footerView.primaryButton.setConnectTitle()
            case .reading:
                pumpIDTextField.isEnabled = false
                activityIndicator.state = .indeterminantProgress
                footerView.primaryButton.isEnabled = false
                footerView.primaryButton.setConnectTitle()
                lastError = nil
            case .completed:
                pumpIDTextField.isEnabled = true
                activityIndicator.state = .completed
                footerView.primaryButton.isEnabled = true
                footerView.primaryButton.resetTitle()
                lastError = nil
            }
        }
    }

    private var lastError: Error? {
        didSet {
            guard oldValue != nil || lastError != nil else {
                return
            }

            var errorText = lastError?.localizedDescription

            if let error = lastError as? LocalizedError {
                let localizedText = [error.errorDescription, error.failureReason, error.recoverySuggestion].compactMap({ $0 }).joined(separator: ". ")

                if !localizedText.isEmpty {
                    errorText = localizedText
                }
            }

            tableView.beginUpdates()
            loadingLabel.text = errorText

            let isHidden = (errorText == nil)
            loadingLabel.isHidden = isHidden
            tableView.endUpdates()
            // If we changed the error text, update the continue state
            if !isHidden {
                updateStateForSettings()
            }
        }
    }

    private func updateStateForSettings() {
        let isReadyToRead = pumpRegionCode != nil && pumpColor != nil && pumpID?.count == 6

        if isReadyToRead {
            continueState = .readyToRead
        } else {
            continueState = .inputSettings
        }
    }

    private func setupPump(with settings: PumpSettings) {
        continueState = .reading

        let pumpOps = MinimedPumpOps(pumpSettings: settings, pumpState: pumpState, delegate: self)
        self.pumpOps = pumpOps
        pumpOps.runSession(withName: "Pump ID Setup", usingSelector: rileyLinkPumpManager.rileyLinkDeviceProvider.firstConnectedDevice, { (session) in
            guard let session = session else {
                DispatchQueue.main.async {
                    self.lastError = PumpManagerError.connection(MinimedPumpManagerError.noRileyLink)
                }
                return
            }

            do {
                _ = try session.tuneRadio()
                let model = try session.getPumpModel()
                var isSentrySetUpNeeded = false
                
                self.pumpFirmwareVersion = try session.getPumpFirmwareVersion()

                // Radio
                if model.hasMySentry {
                    let isSentryEnabled = try session.getOtherDevicesEnabled()

                    if isSentryEnabled {
                        let sentryIDCount = try session.getOtherDevicesIDs().ids.count

                        isSentrySetUpNeeded = (sentryIDCount == 0)
                    } else {
                        isSentrySetUpNeeded = true
                    }
                } else {
                    // Pre-sentry models need a remote ID to decrease the radio wake interval
                    let remoteIDCount = try session.getRemoteControlIDs().ids.count

                    if remoteIDCount == 0 {
                        try session.setRemoteControlID(Data([9, 9, 9, 9, 9, 9]), atIndex: 2)
                    }

                    try session.setRemoteControlEnabled(true)
                }

                // Settings
                let newSchedule = BasalSchedule(repeatingScheduleValues: self.basalSchedule.items)
                try session.setBasalSchedule(newSchedule, for: .standard)
                try session.setMaxBolus(units: self.maxBolusUnits)
                try session.setMaxBasalRate(unitsPerHour: self.maxBasalRateUnitsPerHour)
                try session.selectBasalProfile(.standard)
                try session.setTimeToNow(in: .current)

                DispatchQueue.main.async {
                    self.isSentrySetUpNeeded = isSentrySetUpNeeded

                    if self.pumpState != nil {
                        self.continueState = .completed
                    } else {
                        self.lastError = PumpManagerError.connection(MinimedPumpManagerError.noRileyLink)
                    }
                }
            } catch let error {
                DispatchQueue.main.async {
                    self.lastError = error
                }
            }
        })
    }

    override func shouldPerformSegue(withIdentifier identifier: String, sender: Any?) -> Bool {
        return continueState == .completed
    }

    override func continueButtonPressed(_ sender: Any) {
        if case .completed = continueState {
            if let setupViewController = navigationController as? MinimedPumpManagerSetupViewController,
                let pumpManager = pumpManager // create mdt 1
            {
                setupViewController.pumpManagerSetupComplete(pumpManager)
            }
            if isSentrySetUpNeeded {
                performSegue(withIdentifier: "Sentry", sender: sender)
            } else {
                super.continueButtonPressed(sender)
            }
        } else if case .readyToRead = continueState, let pumpID = pumpID, let pumpRegion = pumpRegionCode?.region {
#if targetEnvironment(simulator)
            self.continueState = .completed
            self.pumpState = PumpState(timeZone: .currentFixed, pumpModel: PumpModel(rawValue:
                "523")!, useMySentry: false)
            self.pumpFirmwareVersion = "2.4Mock"
#else
            setupPump(with: PumpSettings(pumpID: pumpID, pumpRegion: pumpRegion))
#endif
        }
    }

    override func cancelButtonPressed(_ sender: Any) {
        if regionAndColorPickerCell.isFirstResponder {
            regionAndColorPickerCell.resignFirstResponder()
        } else if pumpIDTextField.isFirstResponder {
            pumpIDTextField.resignFirstResponder()
        } else {
            super.cancelButtonPressed(sender)
        }
    }

    @objc func keyboardDidHide() {
        regionAndColorPickerCell.resignFirstResponder()
    }
}


extension MinimedPumpIDSetupViewController: UIPickerViewDelegate, UIPickerViewDataSource {
    private static let regionRows: [RegionCode] = [.northAmerica, .canada, .worldWide]

    private static let colorRows: [PumpColor] = [.blue, .clear, .purple, .smoke, .pink]

    private enum PickerViewComponent: Int {
        case region
        case color

        static let count = 2
    }

    func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
        switch PickerViewComponent(rawValue: component)! {
        case .region:
            return MinimedPumpIDSetupViewController.regionRows[row].rawValue
        case .color:
            return MinimedPumpIDSetupViewController.colorRows[row].rawValue
        }
    }

    func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
        switch PickerViewComponent(rawValue: component)! {
        case .region:
            pumpRegionCode = MinimedPumpIDSetupViewController.regionRows[row]
        case .color:
            pumpColor = MinimedPumpIDSetupViewController.colorRows[row]
        }
    }

    func numberOfComponents(in pickerView: UIPickerView) -> Int {
        return PickerViewComponent.count
    }

    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
        switch PickerViewComponent(rawValue: component)! {
        case .region:
            return MinimedPumpIDSetupViewController.regionRows.count
        case .color:
            return MinimedPumpIDSetupViewController.colorRows.count
        }
    }
}


extension MinimedPumpIDSetupViewController: UITextFieldDelegate {
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        guard let text = textField.text, let stringRange = Range(range, in: text) else {
            updateStateForSettings()
            return true
        }

        let newText = text.replacingCharacters(in: stringRange, with: string)

        if newText.count >= 6 {
            if newText.count == 6 {
                textField.text = newText
                textField.resignFirstResponder()
            }

            updateStateForSettings()
            return false
        }

        textField.text = newText
        updateStateForSettings()
        return false
    }

    func textFieldShouldEndEditing(_ textField: UITextField) -> Bool {
        return true
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
}


extension MinimedPumpIDSetupViewController: PumpOpsDelegate {
    // TODO: create PumpManager and report it to Loop before pump setup
    // No pumpManager available yet, so no device logs.
    func willSend(_ message: String) {}
    func didReceive(_ message: String) {}
    func didError(_ message: String) {}

    func pumpOps(_ pumpOps: PumpOps, didChange state: PumpState) {
        DispatchQueue.main.async {
            self.pumpState = state
        }
    }
}


class RegionAndColorPickerTableViewCell: UITableViewCell {
    override var canBecomeFirstResponder: Bool {
        return true
    }

    fileprivate private(set) lazy var pickerView = UIPickerView()

    override var inputView: UIView? {
        return pickerView
    }

    @IBOutlet weak var regionLabel: UILabel!

    @IBOutlet weak var pumpImageView: UIImageView!
}


private extension SetupButton {
    func setConnectTitle() {
        setTitle(LocalizedString("Connect", comment: "Button title to connect to pump during setup"), for: .normal)
    }
}
