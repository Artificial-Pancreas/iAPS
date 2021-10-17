//
//  OmniPodPumpManager+UI.swift
//  OmniKitUI
//
//  Created by Pete Schwamb on 8/4/18.
//  Copyright © 2018 Pete Schwamb. All rights reserved.
//

import Foundation
import SwiftUI
import UIKit
import LoopKit
import LoopKitUI
import OmniKit
import RileyLinkKitUI

extension OmnipodPumpManager: PumpManagerUI {
    
    static public func setupViewController(insulinTintColor: Color, guidanceColors: GuidanceColors, allowedInsulinTypes: [InsulinType]) -> (UIViewController & PumpManagerSetupViewController & CompletionNotifying) {
        let navVC = OmnipodPumpManagerSetupViewController.instantiateFromStoryboard()
        let insulinSelectionView = InsulinTypeConfirmation(initialValue: .novolog, supportedInsulinTypes: allowedInsulinTypes) { (confirmedType) in
            navVC.insulinType = confirmedType
            let nextViewController = navVC.storyboard?.instantiateViewController(identifier: "RileyLinkSetup") as! RileyLinkSetupTableViewController
            navVC.pushViewController(nextViewController, animated: true)
        }
        let rootVC = UIHostingController(rootView: insulinSelectionView)
        rootVC.title = "Insulin Type"
        navVC.pushViewController(rootVC, animated: false)
        navVC.navigationBar.backgroundColor = .secondarySystemBackground
        return navVC
    }
    
    public func settingsViewController(insulinTintColor: Color, guidanceColors: GuidanceColors, allowedInsulinTypes: [InsulinType]) -> (UIViewController & CompletionNotifying) {
        let settings = OmnipodSettingsViewController(pumpManager: self)
        let nav = SettingsNavigationViewController(rootViewController: settings)
        return nav
    }

    public func deliveryUncertaintyRecoveryViewController(insulinTintColor: Color, guidanceColors: GuidanceColors) -> (UIViewController & CompletionNotifying) {
        
        // Return settings for now; uncertainty recovery not implemented yet
        let settings = OmnipodSettingsViewController(pumpManager: self)
        let nav = SettingsNavigationViewController(rootViewController: settings)
        return nav
    }
    

    public var smallImage: UIImage? {
        return UIImage(named: "Pod", in: Bundle(for: OmnipodSettingsViewController.self), compatibleWith: nil)!
    }
    
    public func hudProvider(insulinTintColor: Color, guidanceColors: GuidanceColors, allowedInsulinTypes: [InsulinType]) -> HUDProvider? {
        return OmnipodHUDProvider(pumpManager: self, insulinTintColor: insulinTintColor, guidanceColors: guidanceColors, allowedInsulinTypes: allowedInsulinTypes)
    }
    
    public static func createHUDView(rawValue: HUDProvider.HUDViewRawState) -> LevelHUDView? {
        return OmnipodHUDProvider.createHUDView(rawValue: rawValue)
    }

}

// MARK: - DeliveryLimitSettingsTableViewControllerSyncSource
extension OmnipodPumpManager {
    public func syncDeliveryLimitSettings(for viewController: DeliveryLimitSettingsTableViewController, completion: @escaping (DeliveryLimitSettingsResult) -> Void) {
        guard let maxBasalRate = viewController.maximumBasalRatePerHour,
            let maxBolus = viewController.maximumBolus else
        {
            completion(.failure(PodCommsError.invalidData))
            return
        }
        
        completion(.success(maximumBasalRatePerHour: maxBasalRate, maximumBolus: maxBolus))
    }
    
    public func syncButtonTitle(for viewController: DeliveryLimitSettingsTableViewController) -> String {
        return LocalizedString("Save", comment: "Title of button to save delivery limit settings")    }
    
    public func syncButtonDetailText(for viewController: DeliveryLimitSettingsTableViewController) -> String? {
        return nil
    }
    
    public func deliveryLimitSettingsTableViewControllerIsReadOnly(_ viewController: DeliveryLimitSettingsTableViewController) -> Bool {
        return false
    }
}

// MARK: - BasalScheduleTableViewControllerSyncSource
extension OmnipodPumpManager {

    public func syncScheduleValues(for viewController: BasalScheduleTableViewController, completion: @escaping (SyncBasalScheduleResult<Double>) -> Void) {
        syncBasalRateSchedule(items: viewController.scheduleItems) { result in
            switch result {
            case .success(let schedule):
                completion(.success(scheduleItems: schedule.items, timeZone: schedule.timeZone))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    public func syncButtonTitle(for viewController: BasalScheduleTableViewController) -> String {
        if self.hasActivePod {
            return LocalizedString("Sync With Pod", comment: "Title of button to sync basal profile from pod")
        } else {
            return LocalizedString("Save", comment: "Title of button to sync basal profile when no pod paired")
        }
    }

    public func syncButtonDetailText(for viewController: BasalScheduleTableViewController) -> String? {
        return nil
    }

    public func basalScheduleTableViewControllerIsReadOnly(_ viewController: BasalScheduleTableViewController) -> Bool {
        return false
    }
}
