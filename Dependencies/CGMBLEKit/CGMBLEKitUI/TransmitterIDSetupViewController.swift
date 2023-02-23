//
//  TransmitterIDSetupViewController.swift
//  CGMBLEKitUI
//
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//

import UIKit
import LoopKit
import LoopKitUI
import CGMBLEKit
import ShareClient

class TransmitterIDSetupViewController: SetupTableViewController {

    lazy private(set) var shareManager = ShareClientManager()

    private func updateShareUsername() {
        shareUsernameLabel.text = shareManager.shareService.username ?? SettingsTableViewCell.TapToSetString
    }

    private(set) var transmitterID: String? {
        get {
            return transmitterIDTextField.text
        }
        set {
            transmitterIDTextField.text = newValue
        }
    }

    private func updateStateForSettings() {
        let isReadyToRead = transmitterID?.count == 6

        if isReadyToRead {
            continueState = .completed
        } else {
            continueState = .inputSettings
        }
    }

    private enum State {
        case loadingView
        case inputSettings
        case completed
    }

    private var continueState: State = .loadingView {
        didSet {
            switch continueState {
            case .loadingView:
                updateStateForSettings()
            case .inputSettings:
                footerView.primaryButton.isEnabled = false
            case .completed:
                footerView.primaryButton.isEnabled = true
            }
        }
    }

    override func continueButtonPressed(_ sender: Any) {
        if continueState == .completed,
            let setupViewController = navigationController as? TransmitterSetupViewController,
            let transmitterID = transmitterID
        {
            setupViewController.completeSetup(state: TransmitterManagerState(transmitterID: transmitterID))
        }
    }

    override func cancelButtonPressed(_ sender: Any) {
        if transmitterIDTextField.isFirstResponder {
            transmitterIDTextField.resignFirstResponder()
        } else {
            super.cancelButtonPressed(sender)
        }
    }

    override func shouldPerformSegue(withIdentifier identifier: String, sender: Any?) -> Bool {
        return continueState == .completed
    }

    // MARK: -

    @IBOutlet private var shareUsernameLabel: UILabel!

    @IBOutlet private var transmitterIDTextField: UITextField!

    override func viewDidLoad() {
        super.viewDidLoad()

        updateShareUsername()

        continueState = .inputSettings
    }

    // MARK: - UITableViewDelegate

    private enum Section: Int {
        case transmitterID
        case share
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        switch Section(rawValue: indexPath.section)! {
        case .transmitterID:
            tableView.deselectRow(at: indexPath, animated: false)
        case .share:
            let authVC = AuthenticationViewController(authentication: shareManager.shareService)
            authVC.authenticationObserver = { [weak self] (service) in
                self?.shareManager.shareService = service
                self?.updateShareUsername()
            }

            show(authVC, sender: nil)
        }
    }
}


extension TransmitterIDSetupViewController: UITextFieldDelegate {
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
