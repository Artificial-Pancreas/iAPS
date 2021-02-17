//
//  MinimedPumpSetupViewController.swift
//  Loop
//
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//

import UIKit
import LoopKit
import LoopKitUI
import MinimedKit
import RileyLinkBLEKit
import RileyLinkKit
import RileyLinkKitUI


public class MinimedPumpManagerSetupViewController: RileyLinkManagerSetupViewController {

    class func instantiateFromStoryboard() -> MinimedPumpManagerSetupViewController {
        return UIStoryboard(name: "MinimedPumpManager", bundle: Bundle(for: MinimedPumpManagerSetupViewController.self)).instantiateInitialViewController() as! MinimedPumpManagerSetupViewController
    }

    override public func viewDidLoad() {
        super.viewDidLoad()

        if #available(iOSApplicationExtension 13.0, *) {
            view.backgroundColor = .systemBackground
        } else {
            view.backgroundColor = .white
        }
        navigationBar.shadowImage = UIImage()
        
        if let pumpIDSetupVC = topViewController as? MinimedPumpIDSetupViewController, let rileyLinkPumpManager = rileyLinkPumpManager {
            pumpIDSetupVC.rileyLinkPumpManager = rileyLinkPumpManager
        }

    }

    private(set) var pumpManager: MinimedPumpManager?
    
    internal var insulinType: InsulinType?

    /*
     1. RileyLink
     - RileyLinkPumpManagerState

     2. Pump
     - PumpSettings
     - PumpColor
     -- Submit --
     - PumpOps
     - PumpState

     3. (Optional) Connect Devices

     4. Time

     5. Basal Rates & Delivery Limits

     6. Pump Setup Complete

     */

    override public func navigationController(_ navigationController: UINavigationController, willShow viewController: UIViewController, animated: Bool) {
        super.navigationController(navigationController, willShow: viewController, animated: animated)

        // Read state values
        let viewControllers = navigationController.viewControllers
        let count = navigationController.viewControllers.count

        if count >= 2 {
            switch viewControllers[count - 2] {
            case let vc as MinimedPumpIDSetupViewController:
                pumpManager = vc.pumpManager
                maxBasalRateUnitsPerHour = vc.maxBasalRateUnitsPerHour
                maxBolusUnits = vc.maxBolusUnits
                basalSchedule = vc.basalSchedule
            default:
                break
            }
        }

        if let setupViewController = viewController as? SetupTableViewController {
            setupViewController.delegate = self
        }

        // Set state values
        switch viewController {
        case let vc as MinimedPumpIDSetupViewController:
            vc.rileyLinkPumpManager = rileyLinkPumpManager
            vc.maxBolusUnits = maxBolusUnits
            vc.maxBasalRateUnitsPerHour = maxBasalRateUnitsPerHour
            vc.basalSchedule = basalSchedule
        case let vc as MinimedPumpSentrySetupViewController:
            vc.pumpManager = pumpManager
        case is MinimedPumpClockSetupViewController:
            break
        case let vc as MinimedPumpSetupCompleteViewController:
            vc.pumpImage = pumpManager?.state.largePumpImage
        default:
            break
        }

        // Adjust the appearance for the main setup view controllers only
        if viewController is SetupTableViewController {
            navigationBar.isTranslucent = false
            navigationBar.shadowImage = UIImage()
        } else {
            navigationBar.isTranslucent = true
            navigationBar.shadowImage = nil
            viewController.navigationItem.largeTitleDisplayMode = .never
        }
    }

    public func navigationController(_ navigationController: UINavigationController, didShow viewController: UIViewController, animated: Bool) {

        // Adjust the appearance for the main setup view controllers only
        if viewController is SetupTableViewController {
            navigationBar.isTranslucent = false
            navigationBar.shadowImage = UIImage()
        } else {
            navigationBar.isTranslucent = true
            navigationBar.shadowImage = nil
        }
    }

    public func pumpManagerSetupComplete(_ pumpManager: PumpManagerUI) {
        setupDelegate?.pumpManagerSetupViewController(self, didSetUpPumpManager: pumpManager)
    }

    override open func finishedSetup() {
        if let pumpManager = pumpManager {
            let settings = MinimedPumpSettingsViewController(pumpManager: pumpManager)
            setViewControllers([settings], animated: true)
        }
    }

    public func finishedSettingsDisplay() {
        completionDelegate?.completionNotifyingDidComplete(self)
    }
}

extension MinimedPumpManagerSetupViewController: SetupTableViewControllerDelegate {
    public func setupTableViewControllerCancelButtonPressed(_ viewController: SetupTableViewController) {
        completionDelegate?.completionNotifyingDidComplete(self)
    }
}
