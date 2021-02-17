//
//  PodReplacementNavigationController.swift
//  OmniKitUI
//
//  Created by Pete Schwamb on 11/28/18.
//  Copyright © 2018 Pete Schwamb. All rights reserved.
//

import Foundation
import OmniKit
import LoopKitUI

class PodReplacementNavigationController: UINavigationController, UINavigationControllerDelegate, CompletionNotifying {

    weak var completionDelegate: CompletionDelegate?

    class func instantiatePodReplacementFlow(_ pumpManager: OmnipodPumpManager) -> PodReplacementNavigationController {
        let vc = UIStoryboard(name: "OmnipodPumpManager", bundle: Bundle(for: PodReplacementNavigationController.self)).instantiateViewController(withIdentifier: "PodReplacementFlow") as! PodReplacementNavigationController
        vc.pumpManager = pumpManager
        return vc
    }

    class func instantiateNewPodFlow(_ pumpManager: OmnipodPumpManager) -> PodReplacementNavigationController {
        let vc = UIStoryboard(name: "OmnipodPumpManager", bundle: Bundle(for: PodReplacementNavigationController.self)).instantiateViewController(withIdentifier: "NewPodFlow") as! PodReplacementNavigationController
        vc.pumpManager = pumpManager
        return vc
    }
    
    class func instantiateInsertCannulaFlow(_ pumpManager: OmnipodPumpManager) -> PodReplacementNavigationController {
        let vc = UIStoryboard(name: "OmnipodPumpManager", bundle: Bundle(for: PodReplacementNavigationController.self)).instantiateViewController(withIdentifier: "InsertCannulaFlow") as! PodReplacementNavigationController
        vc.pumpManager = pumpManager
        return vc
    }

    private(set) var pumpManager: OmnipodPumpManager!

    override func viewDidLoad() {
        super.viewDidLoad()

        if #available(iOSApplicationExtension 13.0, *) {
            // Prevent interactive dismissal
            isModalInPresentation = true
        }
        
        delegate = self
    }
    
    func navigationController(_ navigationController: UINavigationController, willShow viewController: UIViewController, animated: Bool) {

        if let setupViewController = viewController as? SetupTableViewController {
            setupViewController.delegate = self
        }

        switch viewController {
        case let vc as ReplacePodViewController:
            vc.pumpManager = pumpManager
        case let vc as PairPodSetupViewController:
            vc.pumpManager = pumpManager
        case let vc as InsertCannulaSetupViewController:
            vc.pumpManager = pumpManager
        case let vc as PodSetupCompleteViewController:
            vc.pumpManager = pumpManager
        default:
            break
        }

    }

    func completeSetup() {
        completionDelegate?.completionNotifyingDidComplete(self)
    }
}

extension PodReplacementNavigationController: SetupTableViewControllerDelegate {
    func setupTableViewControllerCancelButtonPressed(_ viewController: SetupTableViewController) {
        completionDelegate?.completionNotifyingDidComplete(self)
    }
}
