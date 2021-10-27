//
//  PairPodSetupViewController.swift
//  OmniKitUI
//
//  Created by Pete Schwamb on 9/18/18.
//  Copyright © 2018 Pete Schwamb. All rights reserved.
//

import UIKit
import LoopKit
import LoopKitUI
import RileyLinkKit
import OmniKit
import os.log

class PairPodSetupViewController: SetupTableViewController {
    
    var rileyLinkPumpManager: RileyLinkPumpManager!
    
    var previouslyEncounteredWeakComms: Bool = false
    
    var pumpManager: OmnipodPumpManager! {
        didSet {
            if oldValue == nil && pumpManager != nil {
                pumpManagerWasSet()
            }
        }
    }

    private let log = OSLog(category: "PairPodSetupViewController")

    // MARK: -
    
    @IBOutlet weak var activityIndicator: SetupIndicatorView!
    
    @IBOutlet weak var loadingLabel: UILabel!
    
    private var loadingText: String? {
        didSet {
            tableView.beginUpdates()
            loadingLabel.text = loadingText
            
            let isHidden = (loadingText == nil)
            loadingLabel.isHidden = isHidden
            tableView.endUpdates()
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        continueState = .initial
    }
    
    private func pumpManagerWasSet() {
        // Still priming?
        let primeFinishesAt = pumpManager.state.podState?.primeFinishTime
        let currentTime = Date()
        if let finishTime = primeFinishesAt, finishTime > currentTime {
            self.continueState = .pairing
            let delay = finishTime.timeIntervalSince(currentTime)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                self.continueState = .ready
            }
        }
    }
    
    // MARK: - UITableViewDelegate
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if case .pairing = continueState {
            return
        }
        
        tableView.deselectRow(at: indexPath, animated: true)
    }
    
    // MARK: - State
    
    private enum State {
        case initial
        case pairing
        case priming(finishTime: TimeInterval)
        case fault
        case ready
    }
    
    private var continueState: State = .initial {
        didSet {
            log.default("Changed continueState from %{public}@ to %{public}@", String(describing: oldValue), String(describing: continueState))

            switch continueState {
            case .initial:
                activityIndicator.state = .hidden
                footerView.primaryButton.isEnabled = true
                footerView.primaryButton.setPairTitle()
            case .pairing:
                activityIndicator.state = .indeterminantProgress
                footerView.primaryButton.isEnabled = false
                footerView.primaryButton.setPairTitle()
                lastError = nil
                loadingText = LocalizedString("Pairing…", comment: "The text of the loading label when pairing")
            case .priming(let finishTime):
                activityIndicator.state = .timedProgress(finishTime: CACurrentMediaTime() + finishTime)
                footerView.primaryButton.isEnabled = false
                footerView.primaryButton.setPairTitle()
                lastError = nil
                loadingText = LocalizedString("Priming…", comment: "The text of the loading label when priming")
            case .fault:
                activityIndicator.state = .hidden
                footerView.primaryButton.isEnabled = true
                footerView.primaryButton.setDeactivateTitle()
            case .ready:
                activityIndicator.state = .completed
                footerView.primaryButton.isEnabled = true
                footerView.primaryButton.resetTitle()
                lastError = nil
                loadingText = LocalizedString("Primed", comment: "The text of the loading label when pod is primed")
            }
        }
    }
    
    private var lastError: Error? {
        didSet {
            guard oldValue != nil || lastError != nil else {
                return
            }
            
            var errorStrings: [String]
            var errorText: String
            
            if let error = lastError as? LocalizedError {
                errorStrings = [error.errorDescription, error.failureReason, error.recoverySuggestion].compactMap { $0 }
            } else {
                errorStrings = [lastError?.localizedDescription].compactMap { $0 }
            }
            
            var podCommsError: PodCommsError? = nil
            if let pumpManagerError = lastError as? PumpManagerError {
                switch pumpManagerError {
                case .communication(let error):
                    podCommsError = error as? PodCommsError
                default:
                    break
                }
            }

            if let podCommsError = podCommsError, podCommsError.possibleWeakCommsCause {
                if previouslyEncounteredWeakComms {
                    errorStrings.append(LocalizedString("If the problem persists, move to a new area and try again", comment: "Additional pairing recovery suggestion on multiple pairing failures"))
                } else {
                    previouslyEncounteredWeakComms = true
                }
            }

            errorText = errorStrings.joined(separator: ". ")
            
            if !errorText.isEmpty {
                errorText += "."
            } else if let error = lastError {
                // We have an error but no error text, generate a string to describe the error
                errorText = String(describing: error)
            }
            loadingText = errorText
            
            // If we have an error, update the continue state appropriately
            if let podCommsError = podCommsError {
                if podCommsError.isFaulted {
                    continueState = .fault
                } else {
                    continueState = .initial
                }
            } else if lastError != nil {
                continueState = .initial
            }
        }
    }
    
    // MARK: - Navigation
    
    private func navigateToReplacePod() {
        log.default("Navigating to ReplacePod screen")
        performSegue(withIdentifier: "ReplacePod", sender: nil)
    }

    override func continueButtonPressed(_ sender: Any) {
        switch continueState {
        case .initial:
            pair()
        case .ready:
            super.continueButtonPressed(sender)
        case .fault:
            navigateToReplacePod()
        default:
            break
        }

    }
    
    override func cancelButtonPressed(_ sender: Any) {
        let podState = pumpManager.state.podState

        if podState != nil {
            let confirmVC = UIAlertController(pumpDeletionHandler: {
                self.navigateToReplacePod()
            })
            self.present(confirmVC, animated: true) {}
        } else {
            super.cancelButtonPressed(sender)
        }
    }
    
    // MARK: -
    
    private func pair() {
        self.continueState = .pairing

        pumpManager.pairAndPrime() { (result) in
            DispatchQueue.main.async {
                switch result {
                case .success(let finishTime):
                    self.log.default("Pairing succeeded, finishing in %{public}@ sec", String(describing: finishTime))
                    if finishTime > 0 {
                        self.continueState = .priming(finishTime: finishTime)
                        DispatchQueue.main.asyncAfter(deadline: .now() + finishTime) {
                            self.continueState = .ready
                        }
                    } else {
                        self.continueState = .ready
                    }
                case .failure(let error):
                    self.log.default("Pairing failed with error: %{public}@", String(describing: error))
                    self.lastError = error
                }
            }
        }
    }
}

private extension PodCommsError {
    var possibleWeakCommsCause: Bool {
        switch self {
        case .invalidData, .noResponse, .invalidAddress, .rssiTooLow, .rssiTooHigh, .unexpectedPacketType:
            return true
        default:
            return false
        }
    }
}

private extension SetupButton {
    func setPairTitle() {
        setTitle(LocalizedString("Pair", comment: "Button title to pair with pod during setup"), for: .normal)
    }
    
    func setDeactivateTitle() {
        setTitle(LocalizedString("Deactivate", comment: "Button title to deactivate pod because of fault during setup"), for: .normal)
    }
}

private extension UIAlertController {
    convenience init(pumpDeletionHandler handler: @escaping () -> Void) {
        self.init(
            title: nil,
            message: LocalizedString("Are you sure you want to shutdown this pod?", comment: "Confirmation message for shutting down a pod"),
            preferredStyle: .actionSheet
        )
        
        addAction(UIAlertAction(
            title: LocalizedString("Deactivate Pod", comment: "Button title to deactivate pod"),
            style: .destructive,
            handler: { (_) in
                handler()
        }
        ))
        
        let exit = LocalizedString("Continue", comment: "The title of the continue action in an action sheet")
        addAction(UIAlertAction(title: exit, style: .default, handler: nil))
    }
}
