//
//  OmnipodPumpManagerSetupViewController.swift
//  OmniKitUI
//
//  Created by Pete Schwamb on 8/4/18.
//  Copyright © 2018 Pete Schwamb. All rights reserved.
//

import Foundation

import UIKit
import LoopKit
import LoopKitUI
import OmniKit
import RileyLinkBLEKit
import RileyLinkKit
import RileyLinkKitUI

// PumpManagerSetupViewController
public class OmnipodPumpManagerSetupViewController: RileyLinkManagerSetupViewController {
    
    class func instantiateFromStoryboard() -> OmnipodPumpManagerSetupViewController {
        return UIStoryboard(name: "OmnipodPumpManager", bundle: Bundle(for: OmnipodPumpManagerSetupViewController.self)).instantiateInitialViewController() as! OmnipodPumpManagerSetupViewController
    }

    override public func viewDidLoad() {
        super.viewDidLoad()
        
        if #available(iOSApplicationExtension 13.0, *) {
            view.backgroundColor = .systemBackground
        } else {
            view.backgroundColor = .white
        }
        navigationBar.shadowImage = UIImage()
        
        if let omnipodPairingViewController = topViewController as? PairPodSetupViewController, let rileyLinkPumpManager = rileyLinkPumpManager {
            omnipodPairingViewController.rileyLinkPumpManager = rileyLinkPumpManager
        }
    }
        
    private(set) var pumpManager: OmnipodPumpManager?
    
    internal var insulinType: InsulinType?
    
    /*
     1. RileyLink
     - RileyLinkPumpManagerState
     
     2. Basal Rates & Delivery Limits
     
     3. Pod Pairing/Priming
     
     4. Cannula Insertion
     
     5. Pod Setup Complete
     */
    
    override public func navigationController(_ navigationController: UINavigationController, willShow viewController: UIViewController, animated: Bool) {
        super.navigationController(navigationController, willShow: viewController, animated: animated)

        // Read state values
        let viewControllers = navigationController.viewControllers
        let count = navigationController.viewControllers.count
        
        if count >= 2 {
            switch viewControllers[count - 2] {
            case let vc as PairPodSetupViewController:
                pumpManager = vc.pumpManager
            default:
                break
            }
        }

        if let setupViewController = viewController as? SetupTableViewController {
            setupViewController.delegate = self
        }


        // Set state values
        switch viewController {
        case let vc as PairPodSetupViewController:
            vc.rileyLinkPumpManager = rileyLinkPumpManager
            if let deviceProvider = rileyLinkPumpManager?.rileyLinkDeviceProvider, let basalSchedule = basalSchedule, let insulinType = insulinType {
                let connectionManagerState = rileyLinkPumpManager?.rileyLinkConnectionManagerState
                let schedule = BasalSchedule(repeatingScheduleValues: basalSchedule.items)
                let pumpManagerState = OmnipodPumpManagerState(podState: nil, timeZone: .currentFixed, basalSchedule: schedule, rileyLinkConnectionManagerState: connectionManagerState, insulinType: insulinType)
                let pumpManager = OmnipodPumpManager(
                    state: pumpManagerState,
                    rileyLinkDeviceProvider: deviceProvider,
                    rileyLinkConnectionManager: rileyLinkPumpManager?.rileyLinkConnectionManager)
                vc.pumpManager = pumpManager
                setupDelegate?.pumpManagerSetupViewController(self, didSetUpPumpManager: pumpManager)
            }
        case let vc as InsertCannulaSetupViewController:
            vc.pumpManager = pumpManager
        case let vc as PodSetupCompleteViewController:
            vc.pumpManager = pumpManager
        default:
            break
        }        
    }

    override open func finishedSetup() {
        if let pumpManager = pumpManager {
            let settings = OmnipodSettingsViewController(pumpManager: pumpManager)
            setViewControllers([settings], animated: true)
        }
    }

    public func finishedSettingsDisplay() {
        completionDelegate?.completionNotifyingDidComplete(self)
    }
}

extension OmnipodPumpManagerSetupViewController: SetupTableViewControllerDelegate {
    public func setupTableViewControllerCancelButtonPressed(_ viewController: SetupTableViewController) {
        completionDelegate?.completionNotifyingDidComplete(self)
    }
}
