//
//  MinimedPumpSentrySetupViewController.swift
//  Loop
//
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//

import UIKit
import LoopKit
import LoopKitUI
import MinimedKit


class MinimedPumpSentrySetupViewController: SetupTableViewController {

    var pumpManager: MinimedPumpManager?

    @IBOutlet weak var activityIndicator: SetupIndicatorView!

    @IBOutlet weak var loadingLabel: UILabel!

    override func viewDidLoad() {
        super.viewDidLoad()

        lastError = nil
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        if pumpManager == nil {
            navigationController?.popViewController(animated: true)
        }

        // Select the first row
        tableView.selectRow(at: [1, 0], animated: true, scrollPosition: .none)
    }

    override func continueButtonPressed(_ sender: Any) {
        switch continueState {
        case .notStarted:
            listenForPairing()
        case .listening:
            break
        case .completed:
            if let setupViewController = navigationController as? MinimedPumpManagerSetupViewController,
                let pumpManager = pumpManager
            {
                super.continueButtonPressed(sender)
                setupViewController.pumpManagerSetupComplete(pumpManager)
            }
        }
    }

    // MARK: -

    private enum State {
        case notStarted
        case listening
        case completed
    }

    private var continueState: State = .notStarted {
        didSet {
            switch continueState {
            case .notStarted:
                footerView.primaryButton.isEnabled = true
                activityIndicator.state = .hidden
                footerView.primaryButton.setTitle(LocalizedString("Retry", comment: "Button title to retry sentry setup"), for: .normal)
            case .listening:
                lastError = nil
                activityIndicator.state = .indeterminantProgress
                footerView.primaryButton.isEnabled = false
            case .completed:
                lastError = nil
                activityIndicator.state = .completed
                footerView.primaryButton.isEnabled = true
                footerView.primaryButton.resetTitle()
            }
        }
    }

    private func listenForPairing() {
        guard let pumpManager = pumpManager else {
            continueState = .notStarted
            lastError = PumpManagerError.connection(MinimedPumpManagerError.noRileyLink)
            return
        }

        continueState = .listening

        pumpManager.pumpOps.runSession(withName: "MySentry Pairing", usingSelector: pumpManager.rileyLinkDeviceProvider.firstConnectedDevice) { (session) in
            guard let session = session else {
                DispatchQueue.main.async {
                    self.continueState = .notStarted
                    self.lastError = PumpManagerError.connection(MinimedPumpManagerError.noRileyLink)
                }
                return
            }

            let watchdogID = Data([0xd0, 0x00, 0x07])
            do {
                try session.changeWatchdogMarriageProfile(watchdogID)
                DispatchQueue.main.async {
                    self.continueState = .completed
                }
            } catch let error {
                DispatchQueue.main.async {
                    self.continueState = .notStarted
                    self.lastError = error
                }
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
        }
    }

}


class PumpMenuItemTableViewCell: UITableViewCell {
    override func awakeFromNib() {
        super.awakeFromNib()

        updateLabel(selected: false)
    }

    private func updateLabel(selected: Bool) {
        let font = UIFont(name: "Menlo-Bold", size: 14) ?? UIFont.monospacedDigitSystemFont(ofSize: 14, weight: .medium)
        let metrics = UIFontMetrics(forTextStyle: .body)
        metrics.scaledFont(for: font)

        let paragraphStyle = NSParagraphStyle.default.mutableCopy() as! NSMutableParagraphStyle
        paragraphStyle.firstLineHeadIndent = 15

        let bundle = Bundle(for: type(of: self))
        let textColor = UIColor(named: "Pump Screen Text", in: bundle, compatibleWith: traitCollection)!
        let backgroundColor = UIColor(named: "Pump Screen Background", in: bundle, compatibleWith: traitCollection)!

        textLabel?.backgroundColor = backgroundColor
        textLabel?.attributedText = NSAttributedString(
            string: textLabel?.text ?? "",
            attributes: [
                .backgroundColor: selected ? textColor : backgroundColor,
                .foregroundColor: selected ? backgroundColor : textColor,
                .font: metrics.scaledFont(for: font),
                .paragraphStyle: paragraphStyle,
            ]
        )
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)

        updateLabel(selected: selected)
    }
}
