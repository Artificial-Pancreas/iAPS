//
//  CompletionViewController.swift
//  ResetTransmitter
//
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//

import UIKit
import UserNotifications

class CompletionViewController: UITableViewController {

    @IBOutlet weak var textView: UITextView!

    override func viewDidLoad() {
        super.viewDidLoad()

        if UIApplication.shared.applicationState == .background {
            let content = UNMutableNotificationContent()
            content.badge = 1
            content.title = NSLocalizedString("Transmitter Reset Complete", comment: "Notification title for background completion notification")
            content.body = textView.text
            content.sound = .default

            let request = UNNotificationRequest(identifier: "Completion", content: content, trigger: nil)

            UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
        }
    }

    override func tableView(_ tableView: UITableView, shouldHighlightRowAt indexPath: IndexPath) -> Bool {
        return false
    }

    override func tableView(_ tableView: UITableView, willSelectRowAt indexPath: IndexPath) -> IndexPath? {
        return nil
    }
}
