//
//  CommandResponseViewController.swift
//  MinimedKitUI
//
//  Copyright © 2018 Pete Schwamb. All rights reserved.
//

import UIKit
import LoopKit
import LoopKitUI
import MinimedKit
import RileyLinkKit
import RileyLinkBLEKit


extension CommandResponseViewController {
    typealias T = CommandResponseViewController

    private static let successText = LocalizedString("Succeeded", comment: "A message indicating a command succeeded")

    static func changeTime(ops: PumpOps?, device: RileyLinkDevice) -> T {
        return T { (completionHandler) -> String in
            ops?.runSession(withName: "Set time", using: device) { (session) in
                let response: String
                do {
                    try session.setTimeToNow(in: .current)
                    response = self.successText
                } catch let error {
                    response = String(describing: error)
                }

                DispatchQueue.main.async {
                    completionHandler(response)
                }
            }

            return LocalizedString("Changing time…", comment: "Progress message for changing pump time.")
        }
    }

    static func changeTime(ops: PumpOps?, rileyLinkDeviceProvider: RileyLinkDeviceProvider) -> T {
        return T { (completionHandler) -> String in
            ops?.runSession(withName: "Set time", usingSelector: rileyLinkDeviceProvider.firstConnectedDevice) { (session) in
                let response: String
                do {
                    guard let session = session else {
                        throw PumpManagerError.connection(MinimedPumpManagerError.noRileyLink)
                    }

                    try session.setTimeToNow(in: .current)
                    response = self.successText
                } catch let error {
                    response = String(describing: error)
                }

                DispatchQueue.main.async {
                    completionHandler(response)
                }
            }

            return LocalizedString("Changing time…", comment: "Progress message for changing pump time.")
        }
    }

    static func dumpHistory(ops: PumpOps?, device: RileyLinkDevice) -> T {
        return T { (completionHandler) -> String in
            let calendar = Calendar(identifier: Calendar.Identifier.gregorian)
            let oneDayAgo = calendar.date(byAdding: DateComponents(day: -1), to: Date())

            ops?.runSession(withName: "Get history events", using: device) { (session) in
                let response: String
                do {
                    let (events, _) = try session.getHistoryEvents(since: oneDayAgo!)
                    var responseText = String(format: "Found %d events since %@", events.count, oneDayAgo! as NSDate)
                    for event in events {
                        responseText += String(format:"\nEvent: %@", event.dictionaryRepresentation)
                    }

                    response = responseText
                } catch let error {
                    response = String(describing: error)
                }

                DispatchQueue.main.async {
                    completionHandler(response)
                }
            }

            return LocalizedString("Fetching history…", comment: "Progress message for fetching pump history.")
        }
    }

    static func fetchGlucose(ops: PumpOps?, device: RileyLinkDevice) -> T {
        return T { (completionHandler) -> String in
            let calendar = Calendar(identifier: Calendar.Identifier.gregorian)
            let oneDayAgo = calendar.date(byAdding: DateComponents(day: -1), to: Date())

            ops?.runSession(withName: "Get glucose history", using: device) { (session) in
                let response: String
                do {
                    let events = try session.getGlucoseHistoryEvents(since: oneDayAgo!)
                    var responseText = String(format: "Found %d events since %@", events.count, oneDayAgo! as NSDate)
                    for event in events {
                        responseText += String(format: "\nEvent: %@", event.dictionaryRepresentation)
                    }

                    response = responseText
                } catch let error {
                    response = String(describing: error)
                }

                DispatchQueue.main.async {
                    completionHandler(response)
                }
            }

            return LocalizedString("Fetching glucose…", comment: "Progress message for fetching pump glucose.")
        }
    }

    static func getPumpModel(ops: PumpOps?, device: RileyLinkDevice) -> T {
        return T { (completionHandler) -> String in
            ops?.runSession(withName: "Get Pump Model", using: device) { (session) in
                let response: String
                do {
                    let model = try session.getPumpModel(usingCache: false)
                    response = "Pump Model: \(model)"
                } catch let error {
                    response = String(describing: error)
                }

                DispatchQueue.main.async {
                    completionHandler(response)
                }
            }

            return LocalizedString("Fetching pump model…", comment: "Progress message for fetching pump model.")
        }
    }

    static func mySentryPair(ops: PumpOps?, device: RileyLinkDevice) -> T {
        return T { (completionHandler) -> String in
            var byteArray = [UInt8](repeating: 0, count: 16)
            (device.peripheralIdentifier as NSUUID).getBytes(&byteArray)
            let watchdogID = Data(byteArray[0..<3])

            ops?.runSession(withName: "Change watchdog marriage profile", using: device) { (session) in
                let response: String
                do {
                    try session.changeWatchdogMarriageProfile(watchdogID)
                    response = self.successText
                } catch let error {
                    response = String(describing: error)
                }

                DispatchQueue.main.async {
                    completionHandler(response)
                }
            }

            return LocalizedString(
                "On your pump, go to the Find Device screen and select \"Find Device\"." +
                    "\n" +
                    "\nMain Menu >" +
                    "\nUtilities >" +
                    "\nConnect Devices >" +
                    "\nOther Devices >" +
                    "\nOn >" +
                "\nFind Device",
                comment: "Pump find device instruction"
            )
        }
    }

    static func pressDownButton(ops: PumpOps?, device: RileyLinkDevice) -> T {
        return T { (completionHandler) -> String in
            ops?.runSession(withName: "Press down button", using: device) { (session) in
                let response: String
                do {
                    try session.pressButton(.down)
                    response = self.successText
                } catch let error {
                    response = String(describing: error)
                }

                DispatchQueue.main.async {
                    completionHandler(response)
                }
            }

            return LocalizedString("Sending button press…", comment: "Progress message for sending button press to pump.")
        }
    }

    static func readBasalSchedule(ops: PumpOps?, device: RileyLinkDevice, integerFormatter: NumberFormatter) -> T {
        return T { (completionHandler) -> String in
            ops?.runSession(withName: "Get Basal Settings", using: device) { (session) in
                let response: String
                do {
                    let schedule = try session.getBasalSchedule(for: .profileB)
                    var str = String(format: LocalizedString("%1$@ basal schedule entries\n", comment: "The format string describing number of basal schedule entries: (1: number of entries)"), integerFormatter.string(from: NSNumber(value: schedule?.entries.count ?? 0))!)
                    for entry in schedule?.entries ?? [] {
                        str += "\(String(describing: entry))\n"
                    }
                    response = str
                } catch let error {
                    response = String(describing: error)
                }

                DispatchQueue.main.async {
                    completionHandler(response)
                }
            }

            return LocalizedString("Reading basal schedule…", comment: "Progress message for reading basal schedule")
        }
    }

    static func readPumpStatus(ops: PumpOps?, device: RileyLinkDevice, measurementFormatter: MeasurementFormatter) -> T {
        return T { (completionHandler) -> String in
            ops?.runSession(withName: "Read pump status", using: device) { (session) in
                let response: String
                do {
                    let status = try session.getCurrentPumpStatus()

                    var str = String(format: LocalizedString("%1$@ Units of insulin remaining\n", comment: "The format string describing units of insulin remaining: (1: number of units)"), measurementFormatter.numberFormatter.string(from: NSNumber(value: status.reservoir))!)
                    str += String(format: LocalizedString("Battery: %1$@ volts\n", comment: "The format string describing pump battery voltage: (1: battery voltage)"), measurementFormatter.string(from: status.batteryVolts))
                    str += String(format: LocalizedString("Suspended: %1$@\n", comment: "The format string describing pump suspended state: (1: suspended)"), String(describing: status.suspended))
                    str += String(format: LocalizedString("Bolusing: %1$@\n", comment: "The format string describing pump bolusing state: (1: bolusing)"), String(describing: status.bolusing))
                    
                    response = str
                } catch let error {
                    response = String(describing: error)
                }

                DispatchQueue.main.async {
                    completionHandler(response)
                }
            }

            return LocalizedString("Reading pump status…", comment: "Progress message for reading pump status")
        }
    }

    static func tuneRadio(ops: PumpOps?, device: RileyLinkDevice, measurementFormatter: MeasurementFormatter) -> T {
        return T { (completionHandler) -> String in
            ops?.runSession(withName: "Tune pump", using: device) { (session) in
                let response: String
                do {
                    let scanResult = try session.tuneRadio()

                    var resultDict: [String: Any] = [:]

                    let intFormatter = NumberFormatter()
                    let formatString = LocalizedString("%1$@  %2$@/%3$@  %4$@", comment: "The format string for displaying a frequency tune trial. Extra spaces added for emphesis: (1: frequency in MHz)(2: success count)(3: total count)(4: average RSSI)")

                    resultDict[LocalizedString("Best Frequency", comment: "The label indicating the best radio frequency")] = measurementFormatter.string(from: scanResult.bestFrequency)
                    resultDict[LocalizedString("Trials", comment: "The label indicating the results of each frequency trial")] = scanResult.trials.map({ (trial) -> String in

                        return String(
                            format: formatString,
                            measurementFormatter.string(from: trial.frequency),
                            intFormatter.string(from: NSNumber(value: trial.successes))!,
                            intFormatter.string(from: NSNumber(value: trial.tries))!,
                            intFormatter.string(from: NSNumber(value: trial.avgRSSI))!
                        )
                    })

                    var responseText: String

                    if let data = try? JSONSerialization.data(withJSONObject: resultDict, options: .prettyPrinted), let string = String(data: data, encoding: .utf8) {
                        responseText = string
                    } else {
                        responseText = LocalizedString("No response", comment: "Message display when no response from tuning pump")
                    }

                    response = responseText
                } catch let error {
                    response = String(describing: error)
                }

                DispatchQueue.main.async {
                    completionHandler(response)
                }
            }

            return LocalizedString("Tuning radio…", comment: "Progress message for tuning radio")
        }
    }
}
