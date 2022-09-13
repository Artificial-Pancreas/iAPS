//
//  RadioSelectionTableViewController.swift
//  Loop
//
//  Created by Nate Racklyeft on 8/26/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import UIKit
import LoopKitUI
import MinimedKit


extension RadioSelectionTableViewController: IdentifiableClass {
    typealias T = RadioSelectionTableViewController

    static func insulinDataSource(_ value: InsulinDataSource) -> T {
        let vc = T()

        vc.selectedIndex = value.rawValue
        vc.options = (0..<2).compactMap({ InsulinDataSource(rawValue: $0) }).map { String(describing: $0) }
        vc.contextHelp = LocalizedString("Insulin delivery can be determined from the pump by either interpreting the event history or comparing the reservoir volume over time. Reading event history allows for a more accurate status graph and uploading up-to-date treatment data to Nightscout, at the cost of faster pump battery drain and the possibility of a higher radio error rate compared to reading only reservoir volume. If the selected source cannot be used for any reason, the system will attempt to fall back to the other option.", comment: "Instructions on selecting an insulin data source")

        return vc
    }

    static func batteryChemistryType(_ value: MinimedKit.BatteryChemistryType) -> T {
        let vc = T()

        vc.selectedIndex = value.rawValue
        vc.options = (0..<2).compactMap({ BatteryChemistryType(rawValue: $0) }).map { String(describing: $0) }
        vc.contextHelp = LocalizedString("Alkaline and Lithium batteries decay at differing rates. Alkaline tend to have a linear voltage drop over time whereas lithium cell batteries tend to maintain voltage until halfway through their lifespan. Under normal usage in a Non-MySentry compatible Minimed (x22/x15) insulin pump running Loop, Alkaline batteries last approximately 4 to 5 days. Lithium batteries last between 1-2 weeks. This selection will use different battery voltage decay rates for each of the battery chemistry types and alert the user when a battery is approximately 8 to 10 hours from failure.", comment: "Instructions on selecting battery chemistry type")

        return vc
    }

    static func useMySentry(_ value: Bool) -> T {
        let vc = T()

        vc.selectedIndex = value ? 0 : 1
            
        vc.options = ["Use MySentry", "Do not use MySentry"]
        vc.contextHelp = LocalizedString("Medtronic pump models 523, 723, 554, and 754 have a feature called 'MySentry' that periodically broadcasts the reservoir and pump battery levels.  Listening for these broadcasts allows Loop to communicate with the pump less frequently, which can increase pump battery life.  However, when using this feature the RileyLink stays awake more of the time and uses more of its own battery.  Enabling this may lengthen pump battery life, while disabling it may lengthen RileyLink battery life. This setting is ignored for other pump models.", comment: "Instructions on selecting setting for MySentry")

        return vc
    }
}
