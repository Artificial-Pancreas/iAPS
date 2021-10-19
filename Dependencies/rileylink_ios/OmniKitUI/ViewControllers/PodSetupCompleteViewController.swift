//
//  PodSetupCompleteViewController.swift
//  OmniKitUI
//
//  Created by Pete Schwamb on 9/18/18.
//  Copyright © 2018 Pete Schwamb. All rights reserved.
//

import UIKit
import LoopKitUI
import OmniKit

class PodSetupCompleteViewController: SetupTableViewController {

    @IBOutlet weak var expirationReminderDateCell: ExpirationReminderDateTableViewCell!

    var pumpManager: OmnipodPumpManager! {
        didSet {
            if let expirationReminderDate = pumpManager.expirationReminderDate, let podState = pumpManager.state.podState {
                expirationReminderDateCell.date = expirationReminderDate
                expirationReminderDateCell.datePicker.maximumDate = podState.expiresAt?.addingTimeInterval(-Pod.expirationReminderAlertMinTimeBeforeExpiration)
                expirationReminderDateCell.datePicker.minimumDate = podState.expiresAt?.addingTimeInterval(-Pod.expirationReminderAlertMaxTimeBeforeExpiration)
            }
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.padFooterToBottom = false
        
        self.navigationItem.hidesBackButton = true
        self.navigationItem.rightBarButtonItem = nil

        expirationReminderDateCell.datePicker.datePickerMode = .dateAndTime
        #if swift(>=5.2)
            if #available(iOS 14.0, *) {
                expirationReminderDateCell.datePicker.preferredDatePickerStyle = .wheels
            }
        #endif
        expirationReminderDateCell.titleLabel.text = LocalizedString("Expiration Reminder", comment: "The title of the cell showing the pod expiration reminder date")
        expirationReminderDateCell.datePicker.minuteInterval = 1
        expirationReminderDateCell.delegate = self
    }

    override func continueButtonPressed(_ sender: Any) {
        if let setupVC = navigationController as? OmnipodPumpManagerSetupViewController {
            setupVC.finishedSetup()
        }
        if let replaceVC = navigationController as? PodReplacementNavigationController {
            replaceVC.completeSetup()
        }
        if pumpManager.confirmationBeeps {
            pumpManager.setConfirmationBeeps(enabled: true, completion: { (error) in
                if let error = error {
                    DispatchQueue.main.async {
                        let title = LocalizedString("Error emitting completion confirmation beep", comment: "The alert title for emitting completion beep error")
                        self.present(UIAlertController(with: error, title: title), animated: true)
                    }
                }
            })
        }
    }

    override func tableView(_ tableView: UITableView, willSelectRowAt indexPath: IndexPath) -> IndexPath? {
        tableView.beginUpdates()
        return indexPath
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        tableView.endUpdates()
    }

}

extension PodSetupCompleteViewController: DatePickerTableViewCellDelegate {
    func datePickerTableViewCellDidUpdateDate(_ cell: DatePickerTableViewCell) {
        pumpManager.expirationReminderDate = cell.date
    }
}
