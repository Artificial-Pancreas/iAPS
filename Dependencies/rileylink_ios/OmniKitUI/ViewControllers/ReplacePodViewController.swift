//
//  ReplacePodViewController.swift
//  OmniKitUI
//
//  Created by Pete Schwamb on 11/28/18.
//  Copyright © 2018 Pete Schwamb. All rights reserved.
//

import UIKit
import LoopKitUI
import OmniKit


class ReplacePodViewController: SetupTableViewController {

    enum PodReplacementReason {
        case normal
        case activationTimeout
        case podIncompatible
        case fault(_ podFault: DetailedStatus)
        case canceledPairingBeforeApplication
        case canceledPairing
    }

    var replacementReason: PodReplacementReason = .normal {
        didSet {
            updateButtonTint()
            switch replacementReason {
            case .normal:
                break // Text set in interface builder
            case .activationTimeout:
                instructionsLabel.text = LocalizedString("Activation time exceeded. The pod must be deactivated before pairing with a new one. Please deactivate and discard pod.", comment: "Instructions when deactivating pod that didn't complete activation in time.")
            case .podIncompatible:
                instructionsLabel.text = LocalizedString("Unable to use incompatible pod. The pod must be deactivated before pairing with a new one. Please deactivate and discard pod.", comment: "Instructions when deactivating an incompatible pod")
            case .fault(let podFault):
                var faultDescription = podFault.faultEventCode.localizedDescription
                if let refString = podFault.pdmRef {
                    faultDescription += String(format: " (%@)", refString)
                }
                instructionsLabel.text = String(format: LocalizedString("%1$@. Insulin delivery has stopped. Please deactivate and remove pod.", comment: "Format string providing instructions for replacing pod due to a fault. (1: The fault description)"), faultDescription)
            case .canceledPairingBeforeApplication:
                instructionsLabel.text = LocalizedString("Incompletely set up pod must be deactivated before pairing with a new one. Please deactivate and discard pod.", comment: "Instructions when deactivating pod that has been paired, but not attached.")
            case .canceledPairing:
                instructionsLabel.text = LocalizedString("Incompletely set up pod must be deactivated before pairing with a new one. Please deactivate and remove pod.", comment: "Instructions when deactivating pod that has been paired and possibly attached.")
            }

            tableView.reloadData()
        }
    }
    
    var pumpManager: OmnipodPumpManager! {
        didSet {
            let podState = pumpManager.state.podState

            if let podFault = podState?.fault {
                if podFault.podProgressStatus == .activationTimeExceeded {
                    self.replacementReason = .activationTimeout
                } else {
                    self.replacementReason = .fault(podFault)
                }
            } else if podState?.setupProgress == .activationTimeout {
                self.replacementReason = .activationTimeout
            } else if podState?.setupProgress == .podIncompatible {
                self.replacementReason = .podIncompatible
            } else if podState?.setupProgress.primingNeeded == true {
                self.replacementReason = .canceledPairingBeforeApplication
            } else if podState?.setupProgress.needsCannulaInsertion == true {
                self.replacementReason = .canceledPairing
            } else {
                self.replacementReason = .normal
            }
        }
    }
    
    // MARK: -
    
    @IBOutlet weak var activityIndicator: SetupIndicatorView!
    
    @IBOutlet weak var loadingLabel: UILabel!

    @IBOutlet weak var instructionsLabel: UILabel!


    private var tryCount: Int = 0
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        continueState = .initial
    }
    
    override func setEditing(_ editing: Bool, animated: Bool) {
        super.setEditing(editing, animated: animated)
    }
    
    // MARK: - UITableViewDelegate
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard continueState != .deactivating else {
            return
        }
        
        tableView.deselectRow(at: indexPath, animated: true)
    }

    
    // MARK: - Navigation
    
    private enum State {
        case initial
        case deactivating
        case deactivationFailed
        case continueAfterFailure
        case ready
    }
    
    private var continueState: State = .initial {
        didSet {
            updateButtonTint()
            switch continueState {
            case .initial:
                activityIndicator.state = .hidden
                footerView.primaryButton.isEnabled = true
                footerView.primaryButton.setDeactivateTitle()
            case .deactivating:
                activityIndicator.state = .indeterminantProgress
                footerView.primaryButton.isEnabled = false
                lastError = nil
            case .deactivationFailed:
                activityIndicator.state = .hidden
                footerView.primaryButton.isEnabled = true
                footerView.primaryButton.setRetryTitle()
            case .continueAfterFailure:
                activityIndicator.state = .hidden
                footerView.primaryButton.isEnabled = true
                footerView.primaryButton.resetTitle()
                tableView.beginUpdates()
                loadingLabel.text = LocalizedString("Unable to deactivate pod. Please continue and pair a new one.", comment: "Instructions when pod cannot be deactivated")
                loadingLabel.isHidden = false
                tableView.endUpdates()
            case .ready:
                navigationItem.rightBarButtonItem = nil
                activityIndicator.state = .completed
                footerView.primaryButton.isEnabled = true
                footerView.primaryButton.resetTitle()
                footerView.primaryButton.tintColor = nil
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
                    errorText = localizedText + "."
                }
            }
            
            // If we have an error but no error text, generate a string to describe the error
            if let error = lastError, (errorText == nil || errorText!.isEmpty) {
                errorText = String(describing: error)
            }

            tableView.beginUpdates()
            loadingLabel.text = errorText
            
            let isHidden = (errorText == nil)
            loadingLabel.isHidden = isHidden
            tableView.endUpdates()
        }
    }
    
    override func shouldPerformSegue(withIdentifier identifier: String, sender: Any?) -> Bool {
        return continueState == .ready || continueState == .continueAfterFailure
    }
    
    override func continueButtonPressed(_ sender: Any) {
        switch continueState {
        case .ready, .continueAfterFailure:
            super.continueButtonPressed(sender)
        case .initial, .deactivationFailed:
            continueState = .deactivating
            deactivate()
        case .deactivating:
            break
        }
    }
    
    func deactivate() {
        tryCount += 1

        let continueAfterFailure = tryCount > 1
        pumpManager.deactivatePod(forgetPodOnFail: continueAfterFailure) { (error) in
            DispatchQueue.main.async {
                if let error = error {
                    if continueAfterFailure {
                        self.continueState = .continueAfterFailure
                    } else {
                        self.lastError = error
                        self.continueState = .deactivationFailed
                    }
                } else {
                    self.continueState = .ready
                }
            }
        }
    }

    override func cancelButtonPressed(_ sender: Any) {
        self.dismiss(animated: true, completion: nil)
    }

    private func updateButtonTint() {
        let buttonTint: UIColor?
        if case .normal = replacementReason, case .initial = continueState {
            buttonTint = .deleteColor
        } else {
            buttonTint = nil
        }
        footerView.primaryButton.tintColor = buttonTint
    }

}

private extension SetupButton {
    func setDeactivateTitle() {
        setTitle(LocalizedString("Deactivate Pod", comment: "Button title for pod deactivation"), for: .normal)
    }
    
    func setRetryTitle() {
        setTitle(LocalizedString("Retry Pod Deactivation", comment: "Button title for retrying pod deactivation"), for: .normal)
    }
}


