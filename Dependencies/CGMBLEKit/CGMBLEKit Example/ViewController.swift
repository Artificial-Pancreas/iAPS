//
//  ViewController.swift
//  xDrip5
//
//  Created by Nathan Racklyeft on 10/1/15.
//  Copyright © 2015 Nathan Racklyeft. All rights reserved.
//

import UIKit
import HealthKit
import CGMBLEKit

class ViewController: UIViewController, TransmitterDelegate, UITextFieldDelegate {

    @IBOutlet weak var titleLabel: UILabel!

    @IBOutlet weak var subtitleLabel: UILabel!

    @IBOutlet weak var passiveModeEnabledSwitch: UISwitch!

    @IBOutlet weak var stayConnectedSwitch: UISwitch!

    @IBOutlet weak var transmitterIDField: UITextField!

    @IBOutlet weak var scanningIndicatorView: UIActivityIndicatorView!

    override func viewDidLoad() {
        super.viewDidLoad()

        passiveModeEnabledSwitch.isOn = AppDelegate.sharedDelegate.transmitter?.passiveModeEnabled ?? false

        stayConnectedSwitch.isOn = AppDelegate.sharedDelegate.transmitter?.stayConnected ?? false

        transmitterIDField.text = AppDelegate.sharedDelegate.transmitter?.ID
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        updateIndicatorViewDisplay()
    }

    // MARK: - Actions

    func updateIndicatorViewDisplay() {
        if let transmitter = AppDelegate.sharedDelegate.transmitter, transmitter.isScanning {
            scanningIndicatorView.startAnimating()
        } else {
            scanningIndicatorView.stopAnimating()
        }
    }

    @IBAction func toggleStayConnected(_ sender: UISwitch) {
        AppDelegate.sharedDelegate.transmitter?.stayConnected = sender.isOn
        UserDefaults.standard.stayConnected = sender.isOn

        updateIndicatorViewDisplay()
    }

    @IBAction func togglePassiveMode(_ sender: UISwitch) {
        AppDelegate.sharedDelegate.transmitter?.passiveModeEnabled = sender.isOn
        UserDefaults.standard.passiveModeEnabled = sender.isOn
    }

    @IBAction func start(_ sender: UIButton) {
        let dialog = UIAlertController(title: "Confirm", message: "Start sensor session.", preferredStyle: .alert)

        dialog.addAction(UIAlertAction(title: "OK", style: .default, handler: { (action: UIAlertAction!) in
            AppDelegate.sharedDelegate.commandQueue.enqueue(.startSensor(at: Date()))
        }))

        dialog.addAction(UIAlertAction(title: "Cancel", style: .cancel))

        present(dialog, animated: true, completion: nil)
    }

    @IBAction func calibrate(_ sender: UIButton) {
        let dialog = UIAlertController(title: "Enter BG", message: "Calibrate sensor.", preferredStyle: .alert)

        let unit = HKUnit.milligramsPerDeciliter

        dialog.addTextField { (textField : UITextField!) in
            textField.placeholder = unit.unitString
            textField.keyboardType = .numberPad
        }

        dialog.addAction(UIAlertAction(title: "Calibrate", style: .default, handler: { (action: UIAlertAction!) in
            let textField = dialog.textFields![0] as UITextField
            let minGlucose = HKQuantity(unit: HKUnit.milligramsPerDeciliter, doubleValue: 40)
            let maxGlucose = HKQuantity(unit: HKUnit.milligramsPerDeciliter, doubleValue: 400)

            if let text = textField.text, let entry = Double(text) {
                guard entry >= minGlucose.doubleValue(for: unit) && entry <= maxGlucose.doubleValue(for: unit) else {
                    // TODO: notify the user if the glucose is not in range
                    return
                }
                let glucose = HKQuantity(unit: unit, doubleValue: Double(entry))
                AppDelegate.sharedDelegate.commandQueue.enqueue(.calibrateSensor(to: glucose, at: Date()))
            }
        }))

        dialog.addAction(UIAlertAction(title: "Cancel", style: .cancel))

        present(dialog, animated: true, completion: nil)
    }

    @IBAction func stop(_ sender: UIButton) {
        let dialog = UIAlertController(title: "Confirm", message: "Stop sensor session.", preferredStyle: .alert)

        dialog.addAction(UIAlertAction(title: "OK", style: .default, handler: { (action: UIAlertAction!) in
            AppDelegate.sharedDelegate.commandQueue.enqueue(.stopSensor(at: Date()))
        }))

        dialog.addAction(UIAlertAction(title: "Cancel", style: .cancel))

        present(dialog, animated: true, completion: nil)
    }

    // MARK: - UITextFieldDelegate

    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        if let text = textField.text {
            let newString = text.replacingCharacters(in: range.rangeOfString(text), with: string)

            if newString.count > 6 {
                return false
            } else if newString.count == 6 {
                AppDelegate.sharedDelegate.transmitterID = newString
                textField.text = newString

                textField.resignFirstResponder()

                return false
            }
        }

        return true
    }

    func textFieldDidEndEditing(_ textField: UITextField) {
        if textField.text?.count != 6 {
            textField.text = UserDefaults.standard.transmitterID
        }
    }

    func textFieldShouldEndEditing(_ textField: UITextField) -> Bool {
        return true
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        return true
    }

    // MARK: - TransmitterDelegate

    func transmitter(_ transmitter: Transmitter, didError error: Error) {
        print("Transmitter Error: \(error)")
        titleLabel.text = NSLocalizedString("Error", comment: "Title displayed during error response")

        subtitleLabel.text = "\(error)"
    }

    func transmitter(_ transmitter: Transmitter, didRead glucose: Glucose) {
        let unit = HKUnit.milligramsPerDeciliter
        if let value = glucose.glucose?.doubleValue(for: unit) {
            titleLabel.text = "\(value) \(unit.unitString)"
        } else {
            titleLabel.text = String(describing: glucose.state)
        }


        let date = glucose.readDate
        subtitleLabel.text = DateFormatter.localizedString(from: date, dateStyle: .none, timeStyle: .long)
    }

    func transmitter(_ transmitter: Transmitter, didReadUnknownData data: Data) {
        titleLabel.text = NSLocalizedString("Unknown Data", comment: "Title displayed during unknown data response")
        subtitleLabel.text = data.hexadecimalString
    }
    
    func transmitter(_ transmitter: Transmitter, didReadBackfill glucose: [Glucose]) {
        titleLabel.text = NSLocalizedString("Backfill", comment: "Title displayed during backfill response")
        subtitleLabel.text = String(describing: glucose.map { $0.glucose })
    }
    
    func transmitterDidConnect(_ transmitter: Transmitter) {
        // Ignore
    }

}


private extension NSRange {
    func rangeOfString(_ string: String) -> Range<String.Index> {
        let startIndex = string.index(string.startIndex, offsetBy: location)
        let endIndex = string.index(startIndex, offsetBy: length)
        return startIndex..<endIndex
    }
}

