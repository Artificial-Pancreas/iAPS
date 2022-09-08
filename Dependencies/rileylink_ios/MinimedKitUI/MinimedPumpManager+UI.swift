//
//  MinimedPumpManager+UI.swift
//  Loop
//
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//

import SwiftUI
import UIKit
import LoopKit
import LoopKitUI
import MinimedKit
import RileyLinkKitUI


extension MinimedPumpManager: PumpManagerUI {
    
    public static var onboardingImage: UIImage? {
        return UIImage.pumpImage(in: nil, isLargerModel: false, isSmallImage: true)
    }

    static public func setupViewController(initialSettings settings: PumpManagerSetupSettings, bluetoothProvider: BluetoothProvider, colorPalette: LoopUIColorPalette, allowDebugFeatures: Bool, allowedInsulinTypes: [InsulinType]) -> SetupUIResult<PumpManagerViewController, PumpManagerUI> {
        let navVC = MinimedPumpManagerSetupViewController.instantiateFromStoryboard()
        navVC.supportedInsulinTypes = allowedInsulinTypes
        let didConfirm: (InsulinType) -> Void = { [weak navVC] (confirmedType) in
            if let navVC = navVC {
                navVC.insulinType = confirmedType
                let nextViewController = navVC.storyboard?.instantiateViewController(identifier: "RileyLinkSetup") as! RileyLinkSetupTableViewController
                navVC.pushViewController(nextViewController, animated: true)
            }
        }
        let didCancel: () -> Void = { [weak navVC] in
            if let navVC = navVC {
                navVC.didCancel()
            }
        }
        let insulinSelectionView = InsulinTypeConfirmation(initialValue: .novolog, supportedInsulinTypes: allowedInsulinTypes, didConfirm: didConfirm, didCancel: didCancel)
        let rootVC = UIHostingController(rootView: insulinSelectionView)
        rootVC.title = "Insulin Type"
        navVC.pushViewController(rootVC, animated: false)
        navVC.navigationBar.backgroundColor = .secondarySystemBackground
        navVC.maxBasalRateUnitsPerHour = settings.maxBasalRateUnitsPerHour
        navVC.maxBolusUnits = settings.maxBolusUnits
        navVC.basalSchedule = settings.basalSchedule
        return .userInteractionRequired(navVC)
    }

    public func settingsViewController(bluetoothProvider: BluetoothProvider, colorPalette: LoopUIColorPalette, allowDebugFeatures: Bool, allowedInsulinTypes: [InsulinType]) -> PumpManagerViewController {
        let settings = MinimedPumpSettingsViewController(pumpManager: self, supportedInsulinTypes: allowedInsulinTypes)
        let nav = PumpManagerSettingsNavigationViewController(rootViewController: settings)
        return nav
    }
    
    public func deliveryUncertaintyRecoveryViewController(colorPalette: LoopUIColorPalette, allowDebugFeatures: Bool) -> (UIViewController & CompletionNotifying) {
        // Return settings for now. No uncertainty handling atm.
        let settings = MinimedPumpSettingsViewController(pumpManager: self, supportedInsulinTypes: [])
        let nav = SettingsNavigationViewController(rootViewController: settings)
        return nav
    }
    
    public var smallImage: UIImage? {
        return state.smallPumpImage
    }
    
    public func hudProvider(bluetoothProvider: BluetoothProvider, colorPalette: LoopUIColorPalette, allowedInsulinTypes: [InsulinType]) -> HUDProvider? {
        return MinimedHUDProvider(pumpManager: self, bluetoothProvider: bluetoothProvider, colorPalette: colorPalette, allowedInsulinTypes: allowedInsulinTypes)
    }
    
    public static func createHUDView(rawValue: HUDProvider.HUDViewRawState) -> BaseHUDView? {
        return MinimedHUDProvider.createHUDView(rawValue: rawValue)
    }
}

// MARK: - PumpStatusIndicator
extension MinimedPumpManager {
    
    public var pumpStatusHighlight: DeviceStatusHighlight? {
        return buildPumpStatusHighlight(for: state, recents: recents)
    }
    
    public var pumpLifecycleProgress: DeviceLifecycleProgress? {
        return nil
    }
    
    public var pumpStatusBadge: DeviceStatusBadge? {
        return nil
    }
}
