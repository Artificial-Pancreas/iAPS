//
//  InsertCannulaSetupViewController.swift
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

class InsertCannulaSetupViewController: SetupTableViewController {
    
    var pumpManager: OmnipodPumpManager!
    
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
    
    override func setEditing(_ editing: Bool, animated: Bool) {
        super.setEditing(editing, animated: animated)
    }
    
    // MARK: - UITableViewDelegate
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if case .startingInsertion = continueState {
            return
        }

        tableView.deselectRow(at: indexPath, animated: true)
    }
    
    // MARK: - Navigation
    
    private enum State {
        case initial
        case startingInsertion
        case inserting(finishTime: CFTimeInterval)
        case needsCheckInsertion
        case fault
        case ready
    }
    
    private var continueState: State = .initial {
        didSet {
            switch continueState {
            case .initial:
                activityIndicator.state = .hidden
                footerView.primaryButton.isEnabled = true
                footerView.primaryButton.setInsertCannulaTitle()
            case .startingInsertion:
                activityIndicator.state = .indeterminantProgress
                footerView.primaryButton.isEnabled = false
                lastError = nil
            case .inserting(let finishTime):
                activityIndicator.state = .timedProgress(finishTime: CACurrentMediaTime() + finishTime)
                footerView.primaryButton.isEnabled = false
                lastError = nil
            case .needsCheckInsertion:
                activityIndicator.state = .hidden
                footerView.primaryButton.isEnabled = true
                footerView.primaryButton.setRecheckInsertionTitle()
            case .fault:
                activityIndicator.state = .hidden
                footerView.primaryButton.isEnabled = true
                footerView.primaryButton.setDeactivateTitle()
            case .ready:
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
                    errorText = localizedText + "."
                }
            }
            
            // If we have an error but no error text, generate a string to describe the error
            if let error = lastError, (errorText == nil || errorText!.isEmpty) {
                errorText = String(describing: error)
            }
            loadingText = errorText
            
            let podCommsError: PodCommsError?
            if let pumpManagerError = lastError as? PumpManagerError {
                switch pumpManagerError {
                // Check for a wrapped PodCommsError in the possible PumpManagerError types
                case .communication(let error), .configuration(let error), .connection(let error), .deviceState(let error):
                    podCommsError = error as? PodCommsError
                default:
                    podCommsError = nil
                    break
                }
            } else {
                // Check for a non PumpManagerError PodCommsError
                podCommsError = lastError as? PodCommsError
            }

            // If we have an error, update the continue state depending on whether it's fatal or if the cannula insertion was started or not
            if let podCommsError = podCommsError {
                if podCommsError.isFaulted {
                    continueState = .fault
                } else {
                    continueState = initialOrNeedsCannulaInsertionCheck
                }
            } else if lastError != nil {
                continueState = initialOrNeedsCannulaInsertionCheck
            }
        }
    }

    // .needsCheckInsertion (if cannula insertion has been started but its completion hasn't been verified) or else .initial
    private var initialOrNeedsCannulaInsertionCheck: State {
        if pumpManager.state.podState?.setupProgress == .cannulaInserting {
            return .needsCheckInsertion
        }
        return .initial
    }

    // .ready (if pod setup has been verifed to be complete) or else .needsCheckInsertion
    private var readyOrNeedsCannulaInsertionCheck: State {
        if pumpManager.state.podState?.setupProgress == .completed {
            return .ready
        }
        return .needsCheckInsertion
    }

    private func navigateToReplacePod() {
        performSegue(withIdentifier: "ReplacePod", sender: nil)
    }

    override func continueButtonPressed(_ sender: Any) {
        switch continueState {
        case .initial:
            continueState = .startingInsertion
            insertCannula()
        case .needsCheckInsertion:
            checkCannulaInsertionFinished()
            if pumpManager.state.podState?.setupProgress == .completed {
                super.continueButtonPressed(sender)
            }
        case .ready:
            super.continueButtonPressed(sender)
        case .fault:
            navigateToReplacePod()
        case .startingInsertion, .inserting:
            break
        }
    }
    
    override func cancelButtonPressed(_ sender: Any) {
        let confirmVC = UIAlertController(pumpDeletionHandler: {
            self.navigateToReplacePod()
        })
        present(confirmVC, animated: true) {}
    }
    
    private func insertCannula() {
        guard let podState = pumpManager.state.podState, podState.setupProgress.needsCannulaInsertion else {
            self.continueState = readyOrNeedsCannulaInsertionCheck
            return
        }
        pumpManager.insertCannula() { (result) in
            DispatchQueue.main.async {
                switch(result) {
                case .success(let finishTime):
                    self.continueState = .inserting(finishTime: finishTime)
                    let delay = finishTime
                    if delay > 0 {
                        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                            self.checkCannulaInsertionFinished() // now check if actually ready
                        }
                    } else {
                        self.continueState = self.readyOrNeedsCannulaInsertionCheck
                    }
                case .failure(let error):
                    self.lastError = error
                }
            }
        }
    }

    private func checkCannulaInsertionFinished() {
        activityIndicator.state = .indeterminantProgress
        self.pumpManager.checkCannulaInsertionFinished() { (error) in
            DispatchQueue.main.async {
                if let error = error {
                    self.lastError = error
                }
                self.continueState = self.readyOrNeedsCannulaInsertionCheck
            }
        }
    }
}

private extension SetupButton {
    func setInsertCannulaTitle() {
        setTitle(LocalizedString("Insert Cannula", comment: "Button title to insert cannula during setup"), for: .normal)
    }
    func setRecheckInsertionTitle() {
        setTitle(LocalizedString("Recheck Cannula Insertion", comment: "Button title to recheck cannula insertion during setup"), for: .normal)
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

